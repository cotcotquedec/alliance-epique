"""Oracle of the Elise loop: does every line of Elise have its audio? READ-ONLY for the loop (sealed).

It only reads: the intro folders of her zone introductions first (data/zones/<group>/@intros/, 2026-10-11; in a run
with --all, or --group G without --category: they are in no category), then the categories in level order
(`tools/zone.sh order`, as the readings oracle), each folder's scripts.json (her lines, tools/elise/frame.py),
audio.json, data/elise/state.json and her voice in data/voices.json. `--kind zone|level|companion|quest` (environment FS_ELISE_KIND)
keeps only one kind of line to do (`level`: her level-up lines, data/zones/@elise/levels/, with --all only;
`companion`: her companion lines, data/zones/@elise/companions/, with --all only).
A line is settled when its audio.json entry is hers (engine "elevenlabs", her current voice ID), for this very text
(`text_hash`), its game file exists and its recorded scores pass the judge (checked again here, without Whisper) or
the user validated it by hand, unless the user refused it by hand (pipeline/review.py, 2026-10-10);
or "not_found" after MAX_TRIES failed takes in this run (the next run reopens it, tools/elise/reopen.py). While she
has no voice, nothing is to do (`no_voice`: her lines wait).

Level (the ratchet's counters, they never go down): lines_ok (lines in place) and tries (every take judged).

    python -m tools.loop oracle elise     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from pipeline import companion_lines, level_lines, zone_intros
from tools.elise import frame, judge
from tools.readings import oracle as reading_oracle


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def settled(unit: dict, audio: dict, state: dict, voice: str | None, root: Path | None = None) -> str | None:
    """"ok", "not_found" (in this run) or None (still to do) for one of her lines."""
    root = root or judge.ROOT
    item = ((audio.get(judge.SECTION[unit["kind"]]) or {}).get(str(unit["quest"])) or {}).get(unit["sex"])
    if item and item.get("engine") == judge.ENGINE and item.get("voice_id") == voice and voice \
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


KINDS = {"zone": ("zone",), "level": ("level",), "companion": ("companion",),
         "quest": ("detail", "complete")}  # --kind of a run (environment FS_ELISE_KIND)


def only_kinds() -> tuple[str, ...] | None:
    """The kinds of lines the run is limited to (`--kind zone|level|companion|quest`), or None: all."""
    return KINDS.get(os.environ.get("FS_ELISE_KIND", ""))


def zone_lines(key: str, voice: str | None, state: dict, zones: Path | None = None,
               root: Path | None = None) -> dict:
    """{"todo": [her lines still to do], "ok": n, "not_found": n, "no_voice": n} for a zone. With FS_ELISE_KIND,
    "todo" keeps only those kinds of lines (the counts stay over all her lines)."""
    wanted = only_kinds()
    folder = (zones or judge.ZONES) / key
    units = frame.units(_read(folder / "scripts.json", None))
    audio = _read(folder / "audio.json", {})
    out = {"todo": [], "ok": 0, "not_found": 0, "no_voice": 0}
    for unit in units:
        status = settled(unit, audio, state, voice, root)
        if status:
            out[status] += 1
        elif not voice:
            out["no_voice"] += 1
        elif wanted is None or unit["kind"] in wanted:
            out["todo"].append(unit)
    return out


def ask(run=None, voices_file: Path | None = None, zones: Path | None = None, root: Path | None = None) -> dict:
    voices = _read(voices_file or reading_oracle.voice_oracle.judge.VOICES_FILE, {"npcs": {}})["npcs"]
    voice = judge.voice_id(voices)
    state = _read(judge.STATE, {"lines": {}})
    order = zone_intros.keys(zones) + level_lines.keys(zones) + companion_lines.keys(zones) \
        + (reading_oracle.zones_in_order(run) if run else reading_oracle.zones_in_order())
    todo, totals = [], {"remaining": 0, "lines_ok": 0, "not_found": 0, "no_voice": 0}
    for key in order:
        z = zone_lines(key, voice, state, zones, root)
        if z["todo"]:
            todo.append(key)
        totals["remaining"] += len(z["todo"])
        for k in ("not_found", "no_voice"):
            totals[k] += z[k]
        totals["lines_ok"] += z["ok"]
    tries = sum(e.get("tries", 0) for e in (state.get("lines") or {}).values())
    return {"done": not todo, "next": todo[0] if todo else None, "todo": todo, "remaining": totals["remaining"],
            "not_found": totals["not_found"], "no_voice": totals["no_voice"],
            "level": {"lines_ok": totals["lines_ok"], "tries": tries}}
