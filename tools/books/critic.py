"""Critic of the books pass: after each attempt, writes what is still missing in the backlog
(data/cache/loops/books/backlog.md). It never validates anything; the arbiter does not read it."""

from __future__ import annotations

from pathlib import Path

from pipeline import storage
from tools.books import judge, oracle
from tools.loop import backlog


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    state = judge._read(judge.STATE, {"lines": {}})
    z = oracle.zone_pages(zone, judge.voice_id(), state)
    lines = {k: e for k, e in state["lines"].items() if e.get("zone") == zone}

    def why(unit_id):
        e = lines.get(unit_id) or {}
        failed = (e.get("best") or {}).get("failed") or []
        return f"{unit_id} ({e.get('tries', 0)} tries" + (f", best: {', '.join(judge.REASONS[f] for f in failed)})"
                                                          if failed else ")")

    backlog.record(run_dir, zone, {
        "checked": storage.now(), "last exit code": exit_code, "pages in place": z["ok"],
        "pages still to do": len(z["todo"]), "characters still to read": z["chars"],
        "tried and still to do": [why(u["id"]) for u in z["todo"] if u["id"] in lines],
        "not found in this run (next run: 5 more takes)": [why(k) for k, e in lines.items()
                                                           if e.get("status") == "not_found"],
        "errors in the last output": backlog.error_lines(output_tail)})
