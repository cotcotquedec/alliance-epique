"""Judge of the voice loop: decides whether a candidate voice is good enough. READ-ONLY for the loop (sealed).

The actor generates one candidate take per NPC (data/voices/samples/qwen/candidates/<npc>/s<seed>.wav and its
meta.json) and then runs this judge, which builds the acceptable state: Whisper large-v3 hears each candidate
once (language and transcript), and the candidate
- passes when English ≤ MAX_EN, misread words ≤ MAX_WER and speed within CPS (characters of the text per second
  of audio): it becomes the NPC's voice (voices/<npc>/ref.wav and ref.txt, its exact text, for cloning), and
  voices.json npcs[<npc>].qwen gets status "ok" with its scores;
- fails otherwise: it is deleted, unless it is the NPC's best failed take so far, kept for a human in
  review/<npc>/best.wav (when the thresholds are loosened, a kept take that passes them becomes the voice at the
  start of the next pass, without a new take: `rejudge_kept`); after MAX_TRIES failed takes in the same run of the loop (a campaign), the NPC is
  "not_found" until the next run: never abandoned, each new run of the loop gives it MAX_TRIES more takes
  (tools/voices/reopen.py, run by tools/voices/run.sh).
Every verdict goes to the tries log (data/cache/loops/voices/tries.jsonl). The oracle re-checks the recorded scores
of every voice against these thresholds (`verdict`), without Whisper.

Thresholds, calibrated on 2026-10-07 (96 Qwen3 takes, 31 ElevenLabs samples as well-pronounced controls): English
0.1 % (the user's rule; ElevenLabs is at 0 %), misread words 12 % (the worst ElevenLabs sample is at 10.9 %; the
English-accented takes are at 21-30 %), 7 to 22 characters per second (the slow tauren is at 7.7). Loosened by the
user the same day after the Elwynn quest readings: English 0.15 %, misread words 15 %.

Pure functions at the top (no model, importable from any Python); Whisper loads only in `Whisper`.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import time
import unicodedata
from pathlib import Path

from tools.voices import names

MAX_EN = 0.0015  # Whisper's probability of English (0.001 until 2026-10-07, loosened by the user)
MAX_WER = 0.15  # word error rate of Whisper's transcript against the text (0.12 until 2026-10-07, same)
CPS = (7.0, 22.0)  # characters of the text per second of audio
MAX_TRIES = 5  # failed takes in one run of the loop before the NPC is "not_found" until the next run
WHISPER = "large-v3"

ROOT = Path(__file__).resolve().parents[2]
VOICES_FILE = ROOT / "data" / "voices.json"
SAMPLES = ROOT / "data" / "voices" / "samples" / "qwen"
CANDIDATES = SAMPLES / "candidates"
VOICES = SAMPLES / "voices"
REVIEW = SAMPLES / "review"
TRIES_LOG = ROOT / "data" / "cache" / "loops" / "voices" / "tries.jsonl"

REASONS = {"en": "anglais", "wer": "mots mal lus", "cps": "durée"}


def verdict(scores: dict) -> list[str]:
    """The criteria a take fails (keys of REASONS); empty: the take is good."""
    out = []
    if scores["en"] > MAX_EN:
        out.append("en")
    if scores["wer"] > MAX_WER:
        out.append("wer")
    if not CPS[0] <= scores["cps"] <= CPS[1]:
        out.append("cps")
    return out


def badness(scores: dict) -> tuple:
    """Order of failed takes, the best first: fewest failed criteria, then least English, then fewest errors."""
    return (len(verdict(scores)), scores["en"], scores["wer"])


# Spoken elisions: the sample lines are written as spoken ("j'vous", "l'vieux") and Whisper writes standard French
# ("je vous", "le vieux"); a clitic and its elided form count as the same word.
ELIDED = {"le": "l'", "la": "l'", "je": "j'", "me": "m'", "te": "t'", "se": "s'", "de": "d'", "ne": "n'",
          "que": "qu'", "ce": "c'"}


def words(text: str) -> str:
    """Normalized words for the error rate: lower case, no punctuation, elisions split (l'abbaye: l' abbaye) and
    clitics in their elided form."""
    text = unicodedata.normalize("NFC", text.lower()).replace("’", "'").replace("œ", "oe")
    text = re.sub(r"\b(\w+)'", r"\1' ", text)
    return " ".join(ELIDED.get(w, w) for w in re.findall(r"[\w']+", text))


def word_error_rate(reference: str, hypothesis: str) -> float:
    """Levenshtein distance over words, divided by the reference's word count."""
    ref, hyp = words(reference).split(), words(hypothesis).split()
    row = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        prev, row[0] = row[0], i
        for j, h in enumerate(hyp, 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (r != h))
    return row[-1] / max(len(ref), 1)


class Whisper:
    """Whisper large-v3 (faster-whisper: CPU int8 on the Mac, GPU float16 on a CUDA box, tools/qwen_voices/backend.py):
    one pass gives the language probabilities and the transcript."""

    def __init__(self):
        import soundfile as sf
        import soxr
        from tools.qwen_voices import backend
        self.sf, self.soxr = sf, soxr
        print(f"judge: loading Whisper {WHISPER}...", flush=True)
        self.model = backend.whisper(WHISPER)

    def hear(self, path: Path) -> tuple[dict, str, float]:
        """(language probabilities, transcript, duration in seconds)."""
        audio, sr = self.sf.read(path, dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        audio = self.soxr.resample(audio, sr, 16000) if sr != 16000 else audio
        segments, info = self.model.transcribe(audio, beam_size=5, condition_on_previous_text=False)
        transcript = " ".join(s.text.strip() for s in segments)
        return dict(info.all_language_probs or []), transcript, len(audio) / 16000


def scores_of(probs: dict, transcript: str, text: str, seconds: float) -> dict:
    """The take's scores. Misread words: tolerant of how Whisper spells proper nouns (tools/voices/names.py, adopted
    by the user on 2026-10-13)."""
    return {"en": round(probs.get("en", 0.0), 4), "fr": round(probs.get("fr", 0.0), 4),
            "wer": round(names.tolerant_wer(text, transcript, words), 3), "cps": round(len(text) / max(seconds, 0.01), 1),
            "secs": round(seconds, 1)}


def candidates(npcs: set[str] | None = None) -> list[Path]:
    """The candidate takes waiting for a verdict (of these NPCs only, if given)."""
    return sorted(p for p in CANDIDATES.glob("*/s*.wav") if npcs is None or p.parent.name in npcs)


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def settle(npc: str, take: Path, meta: dict, scores: dict, entry: dict, when: str) -> dict:
    """Applies a verdict on disk (voice, review or deletion) and returns the NPC's new qwen entry."""
    failed = verdict(scores)
    seed = int(meta["seed"])
    entry = {**entry, "tries": entry.get("tries", 0) + 1, "campaign_tries": entry.get("campaign_tries", 0) + 1,
             "seeds": entry.get("seeds", []) + [seed]}
    if not failed:
        folder = VOICES / npc
        folder.mkdir(parents=True, exist_ok=True)
        shutil.move(take, folder / "ref.wav")
        (folder / "ref.txt").write_text(meta["text"] + "\n", encoding="utf-8")
        shutil.rmtree(REVIEW / npc, ignore_errors=True)
        entry.pop("best", None)
        return {**entry, "status": "ok", "seed": seed, "scores": scores, "engine": meta["engine"],
                "temperature": meta["temperature"], "instruct": meta["instruct"], "text": meta["text"],
                "ref": str((folder / "ref.wav").relative_to(ROOT)), "created_at": when}
    best = entry.get("best")
    if best is None or badness(scores) < badness(best["scores"]):
        folder = REVIEW / npc
        folder.mkdir(parents=True, exist_ok=True)
        shutil.move(take, folder / "best.wav")
        entry["best"] = {"seed": seed, "scores": scores, "failed": failed, "text": meta["text"],
                         "instruct": meta["instruct"], "engine": meta["engine"], "temperature": meta["temperature"],
                         "take": str((folder / "best.wav").relative_to(ROOT))}
    else:
        take.unlink()
    entry["status"] = "not_found" if entry["campaign_tries"] >= MAX_TRIES else "pending"
    return entry


def only_npcs() -> set[str] | None:
    """The NPCs a run is limited to (`--npc`, environment FS_NPCS), or None: all."""
    raw = os.environ.get("FS_NPCS", "").replace(",", " ").split()
    return set(raw) or None


def rejudge_kept(now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=print) -> int:
    """Applies the current thresholds to the best failed takes kept for review (their scores are recorded): one
    that passes now (the thresholds were loosened) becomes the NPC's voice, without a new take. Only the NPCs of
    FS_NPCS when set. Returns how many."""
    voices = _read(VOICES_FILE, None)
    wanted, promoted, when = only_npcs(), 0, now()
    for npc, record in voices["npcs"].items():
        entry = record.get("qwen") or {}
        best = entry.get("best")
        if entry.get("status") == "ok" or not best or verdict(best["scores"]) or (wanted and npc not in wanted):
            continue
        take = ROOT / best["take"]
        if not take.is_file():
            continue
        folder = VOICES / npc
        folder.mkdir(parents=True, exist_ok=True)
        shutil.move(take, folder / "ref.wav")
        (folder / "ref.txt").write_text(best["text"] + "\n", encoding="utf-8")
        shutil.rmtree(REVIEW / npc, ignore_errors=True)
        entry.pop("best")
        record["qwen"] = {**entry, "status": "ok", "seed": best["seed"], "scores": best["scores"],
                          "engine": best.get("engine", "?"), "temperature": best.get("temperature"),
                          "instruct": best["instruct"], "text": best["text"],
                          "ref": str((folder / "ref.wav").relative_to(ROOT)), "created_at": when,
                          "promoted": "kept take, thresholds loosened"}
        _log({"at": when, "npc": int(npc), "name": record["name"], "seed": best["seed"], "scores": best["scores"],
              "failed": [], "status": "ok", "promoted": True})
        promoted += 1
        say(f"judge: {npc} {record['name']} s{best['seed']}: kept take passes the current thresholds -> ok")
    if promoted:
        _write(VOICES_FILE, voices)
    return promoted


def _log(line: dict) -> None:
    TRIES_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(TRIES_LOG, "a", encoding="utf-8") as log:
        log.write(json.dumps(line, ensure_ascii=False) + "\n")


def judge(takes: list[Path], hear=None, now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=print) -> dict:
    """Judges these candidate takes, one by one (each verdict is saved at once: an interruption loses nothing).
    `hear`: path -> (language probabilities, transcript, seconds); Whisper by default. Returns the counts."""
    counts = {"ok": 0, "failed": 0, "not_found": 0}
    for take in takes:
        npc, meta_path = take.parent.name, take.with_suffix(".json")
        meta = _read(meta_path, None)
        if meta is None:  # an interrupted generation: no meta, no verdict
            take.unlink()
            continue
        hear = hear or Whisper().hear
        probs, transcript, seconds = hear(take)
        scores = scores_of(probs, transcript, meta["text"], seconds)
        voices = _read(VOICES_FILE, None)
        record = voices["npcs"][npc]
        when = now()
        record["qwen"] = settle(npc, take, meta, scores, record.get("qwen") or {}, when)
        _write(VOICES_FILE, voices)
        meta_path.unlink()
        if not any(take.parent.iterdir()):
            take.parent.rmdir()
        status, failed = record["qwen"]["status"], verdict(scores)
        _log({"at": when, "npc": int(npc), "name": record["name"], "seed": meta["seed"], "scores": scores,
              "failed": failed, "status": status, "heard": transcript})
        counts["ok" if status == "ok" else "not_found" if status == "not_found" else "failed"] += 1
        shown = ", ".join(REASONS[f] for f in failed) or "ok"
        say(f"judge: {npc} {record['name']} s{meta['seed']}: English {scores['en'] * 100:.2f} %, "
            f"misread {scores['wer'] * 100:.0f} %, {scores['cps']} chars/s -> {shown}"
            + (f"; not found after {record['qwen']['campaign_tries']} tries this run" if status == "not_found" else ""))
    return counts
