"""Oracle of the books loop: does every page of every book of the scope have Elise's audio? READ-ONLY for the loop
(sealed).

It only reads: the books folder (data/zones/@books/: scripts.json, section "pages", tools/books/frame.py; audio.json,
section "book"), data/books/state.json and Elise's voice in data/voices.json. The books are in no group nor category:
a run covers them with --all only. A page reading is settled when its audio.json entry is hers (engine "elevenlabs",
her current voice ID), for this very text (`text_hash`), its game file exists and its recorded scores pass the judge
(checked again here, without Whisper) or the user validated it by hand, unless the user refused it by hand
(pipeline/review.py); or "not_found" after MAX_TRIES failed takes in this run (the next run reopens it,
tools/books/reopen.py). While she has no voice, nothing is to do (`no_voice`).

Level (the ratchet's counters, they never go down): pages_ok (page readings in place) and tries (every take judged).

    python -m tools.loop oracle books     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import json
from pathlib import Path

from pipeline import books
from tools.books import frame, judge


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def settled(unit: dict, audio: dict, state: dict, voice: str | None, root: Path | None = None) -> str | None:
    """"ok", "not_found" (in this run) or None (still to do) for one page reading."""
    root = root or judge.ROOT
    item = ((audio.get(judge.SECTION) or {}).get(str(unit["page"])) or {}).get(unit["sex"])
    if item and voice and item.get("engine") == judge.ENGINE and item.get("voice_id") == voice \
            and item.get("text_hash") == frame.text_hash(unit["text"]):
        game = root / "addon" / "ForeverSpeech" / "audio" / item["file"].split("\\audio\\", 1)[-1].replace("\\", "/")
        human = (item.get("validated") or {}).get("by") == "human"  # validated by hand (pipeline/review.py)
        refused = (item.get("refused") or {}).get("by") == "human"  # refused by hand: read again
        if not refused and game.is_file() and (
                human or (item.get("scores") is not None and not judge.verdict(item["scores"]))):
            return "ok"
    entry = (state.get("lines") or {}).get(unit["id"]) or {}
    if entry.get("status") == "not_found" and entry.get("campaign_tries", 0) >= judge.MAX_TRIES:
        return "not_found"
    return None


def zone_pages(key: str, voice: str | None, state: dict, zones: Path | None = None,
               root: Path | None = None) -> dict:
    """{"todo": [page readings still to do], "ok": n, "not_found": n, "no_voice": n, "chars": characters to do}."""
    folder = (zones or judge.ZONES) / key
    units = frame.units(_read(folder / "scripts.json", None))
    audio = _read(folder / "audio.json", {})
    out = {"todo": [], "ok": 0, "not_found": 0, "no_voice": 0, "chars": 0}
    for unit in units:
        status = settled(unit, audio, state, voice, root)
        if status:
            out[status] += 1
        elif not voice:
            out["no_voice"] += 1
        else:
            out["todo"].append(unit)
            out["chars"] += len(unit["text"])
    return out


def ask(run=None, voices_file: Path | None = None, zones: Path | None = None, root: Path | None = None) -> dict:
    voices = _read(voices_file or judge.voice_judge.VOICES_FILE, {"npcs": {}})["npcs"]
    voice = judge.voice_id(voices)
    state = _read(judge.STATE, {"lines": {}})
    todo, totals = [], {"remaining": 0, "pages_ok": 0, "not_found": 0, "no_voice": 0, "chars": 0}
    for key in books.keys(zones):
        z = zone_pages(key, voice, state, zones, root)
        if z["todo"]:
            todo.append(key)
        totals["remaining"] += len(z["todo"])
        for k in ("not_found", "no_voice", "chars"):
            totals[k] += z[k]
        totals["pages_ok"] += z["ok"]
    tries = sum(e.get("tries", 0) for e in (state.get("lines") or {}).values())
    return {"done": not todo, "next": todo[0] if todo else None, "todo": todo, "remaining": totals["remaining"],
            "chars": totals["chars"], "not_found": totals["not_found"], "no_voice": totals["no_voice"],
            "level": {"pages_ok": totals["pages_ok"], "tries": tries}}
