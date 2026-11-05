"""Critic of the dialogues pass: after each attempt, writes what the zone still misses in the backlog
(data/cache/loops/dialogues/backlog.md). It never validates anything; the arbiter does not read it."""

from __future__ import annotations

import json
from pathlib import Path

from pipeline import storage
from tools.dialogues import judge, oracle
from tools.loop import backlog


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    voices = json.loads(judge.voice_judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
    z = oracle.zone_dialogues(zone, voices)
    state = judge._read(judge.state_file(zone), {}).get("readings", {})

    def why(unit_id):
        e = state.get(unit_id) or {}
        failed = (e.get("best") or {}).get("failed") or []
        return f"{unit_id} ({e.get('tries', 0)} tries" + (f", best: {', '.join(judge.REASONS[f] for f in failed)})"
                                                          if failed else ")")

    backlog.record(run_dir, zone, {
        "checked": storage.now(), "last exit code": exit_code, "dialogue readings in place": z["ok"],
        "still to do": [why(u["id"]) for u in z["todo"]],
        "not found in this run (next run: 5 more takes)": [why(k) for k, e in state.items()
                                                           if e.get("status") == "not_found"],
        "waiting for their NPC's model voice": z["waiting_voice"],
        "errors in the last output": backlog.error_lines(output_tail)})
