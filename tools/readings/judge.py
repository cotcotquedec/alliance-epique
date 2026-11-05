"""Judge of the readings loop: decides whether a quest reading is good enough. READ-ONLY for the loop (sealed).

The actor generates one candidate take per reading still to do (data/voices/samples/qwen/reading_candidates/<zone>/
<reading>_s<seed>.wav and .json) and runs this judge, which builds the acceptable state. Whisper large-v3 hears the
take once, ECAPA compares its timbre with the NPC's model voice. The take passes when it meets the voice loop's
thresholds (tools/voices/judge.py: English, misread words, speed) and its similarity to the model voice is at least
MIN_SIM; then it becomes the quest's audio:
- the game file addon/ForeverSpeech/audio/<npc>/<quest>_<kind>[_f].ogg and the master
  data/audio/<zone>/<npc>/<quest>_<kind>[_f].flac;
- its entry in the zone's audio.json (the index contract's source, pipeline/build_index.py), with its scores.
A failed take is deleted, unless it is the reading's best so far (kept for a human in reading_review/; when the
thresholds are loosened, a kept take that passes them becomes the audio at the start of the next pass,
`rejudge_kept`). After MAX_TRIES failed takes in one run of the loop, the reading is "not_found" until the next
run (never abandoned).
The state of every reading (tries, seeds, status, best failed take) is in the zone's readings.json; every verdict
goes to data/cache/loops/readings/tries.jsonl.

MIN_SIM: on the Adjoint Willem's 16 takes (2026-10-07), quest starts 0.90-0.94, short quest ends 0.80-0.86; another
voice (his former ElevenLabs readings) 0.19-0.31.

Short takes (2026-10-12, decided by the user, rule B): ECAPA's similarity and Whisper's language guess are unreliable
on a few seconds of audio (under 3 s, 244 takes refused for 79 accepted; their median similarity 0.63). Under
SHORT_SIM's durations the similarity asked is lower, and under SHORT_EN's the English allowed is higher; from 5 s on,
the thresholds are unchanged. Simulated on the best kept takes: 47 readings and 111 dialogue pages pass at once.
"""

from __future__ import annotations

import json
import shutil
import time
from pathlib import Path

from tools.voices import judge as voice_judge

MIN_SIM = 0.75  # speaker similarity (ECAPA cosine) to the NPC's model voice
SHORT_SIM = ((3.0, 0.65), (5.0, 0.70))  # (take shorter than these seconds, similarity asked), shortest first
SHORT_EN = (5.0, 0.005)  # a take shorter than this: English allowed up to 0.5 % (else voice_judge.MAX_EN)
MAX_TRIES = voice_judge.MAX_TRIES  # failed takes in one run before the reading is "not_found" until the next run
MODEL = "qwen3-tts-1.7b-base"  # audio.json "model" of an accepted reading

ROOT = voice_judge.ROOT
ZONES = ROOT / "data" / "zones"
SAMPLES = ROOT / "data" / "voices" / "samples" / "qwen"
CANDIDATES = SAMPLES / "reading_candidates"
REVIEW = SAMPLES / "reading_review"
GAME_AUDIO = ROOT / "addon" / "ForeverSpeech" / "audio"
MASTERS = ROOT / "data" / "audio"
TRIES_LOG = ROOT / "data" / "cache" / "loops" / "readings" / "tries.jsonl"
SECTION = {"detail": "audio", "complete": "complete"}  # audio.json section of each kind
REASONS = {**voice_judge.REASONS, "sim": "autre voix"}


def min_sim(secs: float | None) -> float:
    """The similarity asked of a take of this length (seconds; unknown: MIN_SIM)."""
    for below, asked in SHORT_SIM:
        if secs is not None and secs < below:
            return asked
    return MIN_SIM


def max_en(secs: float | None) -> float:
    return SHORT_EN[1] if secs is not None and secs < SHORT_EN[0] else voice_judge.MAX_EN


def verdict(scores: dict) -> list[str]:
    """The criteria a reading fails (keys of REASONS); empty: the reading is good. Short takes: see SHORT_SIM."""
    secs = scores.get("secs")
    out = [r for r in voice_judge.verdict(scores) if r != "en" or scores["en"] > max_en(secs)]
    return out + (["sim"] if scores.get("sim", 0.0) < min_sim(secs) else [])


def badness(scores: dict) -> tuple:
    return (len(verdict(scores)), scores["en"], scores["wer"], -scores.get("sim", 0.0))


def flat(zone: str) -> str:
    return zone.replace("/", "-")


def game_file(npc: int, unit_id: str) -> str:
    """The path the addon plays (index contract): Interface\\AddOns\\ForeverSpeech\\audio\\<npc>\\<id>.ogg."""
    return f"Interface\\AddOns\\ForeverSpeech\\audio\\{npc}\\{unit_id}.ogg"


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def state_file(zone: str) -> Path:
    return ZONES / zone / "readings.json"


def audio_file(zone: str) -> Path:
    return ZONES / zone / "audio.json"


class Ears:
    """Whisper large-v3 (language, transcript) and ECAPA (timbre); the NPCs' model voices are encoded once."""

    def __init__(self):
        import numpy as np
        import soundfile as sf
        import soxr
        import torch
        from speechbrain.inference.speaker import EncoderClassifier

        from tools.qwen_voices import backend
        self.np, self.sf, self.soxr, self.torch = np, sf, soxr, torch
        self.whisper = voice_judge.Whisper()
        self.device = backend.torch_device()
        print(f"judge: loading ECAPA on {self.device}...", flush=True)
        self.ecapa = EncoderClassifier.from_hparams("speechbrain/spkrec-ecapa-voxceleb",
                                                    run_opts={"device": self.device})
        self.models = {}

    def _embedding(self, path: Path):
        x, sr = self.sf.read(path, dtype="float32")
        x = x.mean(axis=1) if x.ndim > 1 else x
        x = self.soxr.resample(x, sr, 16000) if sr != 16000 else x
        with self.torch.no_grad():
            e = self.ecapa.encode_batch(self.torch.from_numpy(x).unsqueeze(0).to(self.device)).squeeze().cpu().numpy()
        return e / self.np.linalg.norm(e)

    def similarity(self, take: Path, model_voice: Path) -> float:
        key = str(model_voice)
        if key not in self.models:
            self.models[key] = self._embedding(model_voice)
        return float(self._embedding(take) @ self.models[key])

    def scores(self, take: Path, text: str, model_voice: Path) -> tuple[dict, str]:
        probs, heard, seconds = self.whisper.hear(take)
        scores = voice_judge.scores_of(probs, heard, text, seconds)
        scores["sim"] = round(self.similarity(take, model_voice), 3)
        return scores, heard


def candidates(zone: str) -> list[Path]:
    """The candidate takes of a zone ready for a verdict (their meta written last: generation finished)."""
    folder = CANDIDATES / flat(zone)
    return sorted(p for p in folder.glob("*.wav") if p.with_suffix(".json").exists())


def accept(zone: str, take: Path, meta: dict, scores: dict, when: str) -> dict:
    """Puts an accepted take in place (game ogg, master FLAC) and returns its audio.json variant entry."""
    from pipeline.voices import audio
    npc, unit = meta["npc"], meta["id"]
    ogg = GAME_AUDIO / str(npc) / f"{unit}.ogg"
    master = MASTERS / zone / str(npc) / f"{unit}.flac"
    ogg.parent.mkdir(parents=True, exist_ok=True)
    master.parent.mkdir(parents=True, exist_ok=True)
    audio.to_ogg(take, ogg)
    audio.to_flac(take, master)
    return {"file": game_file(npc, unit), "master": str(master.relative_to(ROOT)), "dur": scores["secs"],
            "cps": scores["cps"], "model": MODEL, "engine": meta["engine"], "seed": meta["seed"], "scores": scores,
            "text": meta["text"], "stamp": {"voice": f"q{meta['voice_seed']}", "voice_seed": meta["voice_seed"]},
            "created_at": when}


def _say(line: str) -> None:
    print(line, flush=True)


def _log(line: dict) -> None:
    TRIES_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(TRIES_LOG, "a", encoding="utf-8") as log:
        log.write(json.dumps(line, ensure_ascii=False) + "\n")


def rejudge_kept(zone: str, now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=_say) -> int:
    """Applies the current thresholds to the best failed takes kept for review (their scores are recorded): one
    that passes now (the thresholds were loosened) becomes the quest's audio, without a new take. Only the NPCs of
    FS_NPCS when set; each promotion goes to the tries log. Returns how many."""
    state = _read(state_file(zone), None)
    if not state:
        return 0
    from tools.readings import frame
    texts = {u["id"]: u["text"] for u in frame.units(_read(ZONES / zone / "scripts.json", None))}
    voices = _read(voice_judge.VOICES_FILE, {"npcs": {}})["npcs"]
    wanted = voice_judge.only_npcs()
    promoted = 0
    for unit, entry in state["readings"].items():
        best = entry.get("best")
        if entry.get("status") == "ok" or not best or verdict(best["scores"]) or \
                (wanted and str(entry["npc"]) not in wanted):
            continue
        take = ROOT / best["take"]
        if not take.is_file():
            continue
        voice_seed = best.get("voice_seed") or ((voices.get(str(entry["npc"])) or {}).get("qwen") or {}).get("seed")
        meta = {"id": unit, "npc": entry["npc"], "seed": best["seed"], "engine": best.get("engine", frame.REPO),
                "text": best.get("text") or texts.get(unit, ""), "voice_seed": voice_seed}
        data = _read(audio_file(zone), {"schema": 1, "audio": {}, "complete": {}})
        item = data.setdefault(SECTION[entry["kind"]], {}).setdefault(str(entry["quest"]), {"npc": entry["npc"]})
        item[entry["sex"]] = accept(zone, take, meta, best["scores"], now())
        _write(audio_file(zone), data)
        shutil.rmtree(take.parent, ignore_errors=True)
        entry.pop("best")
        entry.update(status="ok", seed=best["seed"], scores=best["scores"], promoted="kept take, thresholds loosened")
        _log({"at": now(), "zone": zone, "reading": unit, "npc": entry["npc"], "seed": best["seed"],
              "scores": best["scores"], "failed": [], "status": "ok", "promoted": True})
        promoted += 1
        say(f"judge: {unit} (PNJ {entry['npc']}) s{best['seed']}: kept take passes the current thresholds -> ok")
    if promoted:
        _write(state_file(zone), state)
    return promoted


def judge_take(zone: str, take: Path, ears: Ears, now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=_say) -> str:
    """Judges one candidate take; saves the verdict at once. Returns the reading's new status."""
    meta = _read(take.with_suffix(".json"), None)
    unit = meta["id"]
    model_voice = ROOT / meta["voice_ref"]
    scores, heard = ears.scores(take, meta["text"], model_voice)
    failed, when = verdict(scores), now()
    state = _read(state_file(zone), {"schema": 1, "readings": {}})
    entry = state["readings"].get(unit) or {}
    entry = {**entry, "quest": meta["quest"], "kind": meta["kind"], "sex": meta["sex"], "npc": meta["npc"],
             "tries": entry.get("tries", 0) + 1, "campaign_tries": entry.get("campaign_tries", 0) + 1,
             "seeds": entry.get("seeds", []) + [meta["seed"]]}
    if not failed:
        data = _read(audio_file(zone), {"schema": 1, "audio": {}, "complete": {}})
        section = data.setdefault(SECTION[meta["kind"]], {})
        item = section.setdefault(str(meta["quest"]), {"npc": meta["npc"]})
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
    say(f"judge: {unit} (PNJ {meta['npc']}) s{meta['seed']}: English {scores['en'] * 100:.2f} %, misread "
        f"{scores['wer'] * 100:.0f} %, {scores['cps']} chars/s, voice {scores['sim']:.2f} -> "
        + (", ".join(REASONS[f] for f in failed) or "ok")
        + ("; not found in this run" if entry["status"] == "not_found" else ""))
    return entry["status"]
