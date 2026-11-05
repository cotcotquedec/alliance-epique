"""Oracle of the readings loop: does every quest text whose NPC has a model voice have its audio? READ-ONLY for the
loop (sealed).

It only reads: the categories in level order (`tools/zone.sh order --side alliance`), each category's scripts.json
(the readings, tools/readings/frame.py), audio.json and readings.json, and data/voices.json. A reading is to do when
its NPC has a validated model voice (voice loop) and it is not settled. Settled: a Qwen3 reading in audio.json for
that quest, kind and player sex, whose game file exists and whose recorded scores pass the judge
(tools/readings/judge.py `verdict`, checked again here, without Whisper), or that the user validated by hand
(`validated: {by: human}`, 2026-10-10), unless the user refused it by hand (`refused: {by: human}`); or "not_found"
after MAX_TRIES failed
takes in this run of the loop (the next run reopens it, tools/readings/reopen.py). A reading whose NPC has no model
voice yet waits for the voice loop (`waiting_voice`).

Level (the ratchet's counters, they never go down): readings_ok (readings in place) and tries (every take judged,
archived ones included). Also reported: `remaining` (readings still to do, of the NPCs of `--npc` if any),
`not_found` (in this run), `waiting_voice`, `todo` (categories with readings still to do, in level order).

    python -m tools.loop oracle readings     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from tools.readings import frame, judge
from tools.voices import oracle as voice_oracle

def zones_in_order(run=subprocess.run) -> list[str]:
    return voice_oracle.zones_in_order(run)


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def has_voice(voices: dict, npc: int) -> bool:
    return voice_oracle.settled((voices.get(str(npc)) or {}).get("qwen")) == "ok"


def settled(unit: dict, audio: dict, state: dict, root: Path | None = None) -> str | None:
    """"ok", "not_found" (in this run) or None (still to do) for a reading of frame.units."""
    root = root or judge.ROOT
    item = ((audio.get(judge.SECTION[unit["kind"]]) or {}).get(str(unit["quest"])) or {}).get(unit["sex"])
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


def only_npcs() -> set[int] | None:
    """The NPCs the run is limited to (`--npc`, environment FS_NPCS), or None: all."""
    raw = os.environ.get("FS_NPCS", "").replace(",", " ").split()
    return {int(n) for n in raw} if raw else None


def zone_readings(key: str, voices: dict, zones: Path | None = None, root: Path | None = None) -> dict:
    """{"todo": [units still to do], "ok": n, "not_found": n, "waiting_voice": n, "tries": n} for a zone; with
    FS_NPCS, "todo" keeps only those NPCs' readings."""
    folder = (zones or judge.ZONES) / key
    units = frame.units(_read(folder / "scripts.json", None))
    audio, state = _read(folder / "audio.json", {}), _read(folder / "readings.json", {})
    wanted = only_npcs()
    entries = [*(state.get("readings") or {}).values(), *state.get("history", [])]  # archived ones: redo.py
    out = {"todo": [], "ok": 0, "not_found": 0, "waiting_voice": 0, "tries": sum(e.get("tries", 0) for e in entries)}
    for unit in units:
        status = settled(unit, audio, state, root)
        if status:
            out[status] += 1
        elif not has_voice(voices, unit["npc"]):
            out["waiting_voice"] += 1
        elif wanted is None or unit["npc"] in wanted:
            out["todo"].append(unit)
    return out


def ask(run=subprocess.run, voices_file: Path | None = None, zones: Path | None = None,
        root: Path | None = None) -> dict:
    voices = _read(voices_file or voice_oracle.judge.VOICES_FILE, {"npcs": {}})["npcs"]
    todo, totals = [], {"remaining": 0, "readings_ok": 0, "not_found": 0, "waiting_voice": 0, "tries": 0}
    for key in zones_in_order(run):
        z = zone_readings(key, voices, zones, root)
        if z["todo"]:
            todo.append(key)
        totals["remaining"] += len(z["todo"])
        for k in ("not_found", "waiting_voice", "tries"):
            totals[k] += z[k]
        totals["readings_ok"] += z["ok"]
    return {"done": not todo, "next": todo[0] if todo else None, "todo": todo, "remaining": totals["remaining"],
            "not_found": totals["not_found"], "waiting_voice": totals["waiting_voice"],
            "level": {"readings_ok": totals["readings_ok"], "tries": totals["tries"]}}
