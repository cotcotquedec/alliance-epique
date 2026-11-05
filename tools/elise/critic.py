"""Critic of the Elise pass: after each attempt, writes what the zone still misses in the backlog
(data/cache/loops/elise/backlog.md). It never validates anything; the arbiter does not read it."""

from __future__ import annotations

from pathlib import Path

from pipeline import storage
from tools.elise import judge, oracle
from tools.loop import backlog


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    state = judge._read(judge.STATE, {"lines": {}})
    z = oracle.zone_lines(zone, judge.voice_id(), state)
    lines = {k: e for k, e in state["lines"].items() if e.get("zone") == zone}

    def why(unit_id):
        e = lines.get(unit_id) or {}
        failed = (e.get("best") or {}).get("failed") or []
        return f"{unit_id} ({e.get('tries', 0)} tries" + (f", best: {', '.join(judge.REASONS[f] for f in failed)})"
                                                          if failed else ")")

    backlog.record(run_dir, zone, {
        "checked": storage.now(), "last exit code": exit_code, "lines in place": z["ok"],
        "lines still to do": [why(u["id"]) for u in z["todo"]],
        "not found in this run (next run: 5 more takes)": [why(k) for k, e in lines.items()
                                                           if e.get("status") == "not_found"],
        "errors in the last output": backlog.error_lines(output_tail)})
