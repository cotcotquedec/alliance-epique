"""Oracle of the dialogues loop: does every dialogue page whose NPC has a model voice have its audio? READ-ONLY for
the loop (sealed).

It only reads: the categories in level order (as the readings oracle), each category's scripts.json (section
"dialogues", tools/dialogues/frame.py), dialogue_audio.json and dialogue_readings.json, and data/voices.json. A
reading is to do when its NPC has a validated model voice and it is not settled: a Qwen3 reading in
dialogue_audio.json whose game file exists and whose recorded scores pass the judge (checked again here, without
Whisper) or that the user validated by hand, unless the user refused it by hand (pipeline/review.py); or
"not_found" after MAX_TRIES failed takes in this run (the next run reopens it). A reading whose NPC has no model
voice yet waits for the voice loop (`waiting_voice`).

Level (the ratchet's counters, they never go down): dialogues_ok and tries.

    python -m tools.loop oracle dialogues     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import json
from pathlib import Path

from tools.dialogues import frame, judge
from tools.readings import oracle as reading_oracle

has_voice, only_npcs = reading_oracle.has_voice, reading_oracle.only_npcs


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def settled(unit: dict, audio: dict, state: dict, root: Path | None = None) -> str | None:
    root = root or judge.ROOT
    item = ((audio.get(judge.SECTION) or {}).get(unit["key"]) or {}).get(unit["sex"])
    if item:
        game = root / "addon" / "ForeverSpeech" / "audio" / item["file"].split("\\audio\\", 1)[-1].replace("\\", "/")
        scores = item.get("scores")
        human = (item.get("validated") or {}).get("by") == "human"  # validated by hand (pipeline/review.py)
        refused = (item.get("refused") or {}).get("by") == "human"  # refused by hand: made again
        if item.get("model") == judge.MODEL and not refused and game.is_file() and (
                human or (scores is not None and not judge.verdict(scores))):
            return "ok"
    entry = (state.get("readings") or {}).get(unit["id"]) or {}
    if entry.get("status") == "not_found" and entry.get("campaign_tries", 0) >= judge.MAX_TRIES:
        return "not_found"
    return None


def zone_dialogues(key: str, voices: dict, zones: Path | None = None, root: Path | None = None) -> dict:
    """{"todo": [readings still to do], "ok", "not_found", "waiting_voice", "tries"} for a zone (FS_NPCS: only
    those NPCs' readings are to do)."""
    folder = (zones or judge.ZONES) / key
    units = frame.units(_read(folder / "scripts.json", None))
    audio, state = _read(folder / "dialogue_audio.json", {}), _read(folder / "dialogue_readings.json", {})
    wanted = only_npcs()
    out = {"todo": [], "ok": 0, "not_found": 0, "waiting_voice": 0,
           "tries": sum(e.get("tries", 0) for e in (state.get("readings") or {}).values())}
    for unit in units:
        status = settled(unit, audio, state, root)
        if status:
            out[status] += 1
        elif not has_voice(voices, unit["npc"]):
            out["waiting_voice"] += 1
        elif wanted is None or unit["npc"] in wanted:
            out["todo"].append(unit)
    return out


def ask(run=None, voices_file: Path | None = None, zones: Path | None = None, root: Path | None = None) -> dict:
    voices = _read(voices_file or reading_oracle.voice_oracle.judge.VOICES_FILE, {"npcs": {}})["npcs"]
    order = reading_oracle.zones_in_order(run) if run else reading_oracle.zones_in_order()
    todo, totals = [], {"remaining": 0, "dialogues_ok": 0, "not_found": 0, "waiting_voice": 0, "tries": 0}
    for key in order:
        z = zone_dialogues(key, voices, zones, root)
        if z["todo"]:
            todo.append(key)
        totals["remaining"] += len(z["todo"])
        for k in ("not_found", "waiting_voice", "tries"):
            totals[k] += z[k]
        totals["dialogues_ok"] += z["ok"]
    return {"done": not todo, "next": todo[0] if todo else None, "todo": todo, "remaining": totals["remaining"],
            "not_found": totals["not_found"], "waiting_voice": totals["waiting_voice"],
            "level": {"dialogues_ok": totals["dialogues_ok"], "tries": totals["tries"]}}
