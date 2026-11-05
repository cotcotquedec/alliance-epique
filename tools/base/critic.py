"""Critic of the base pass: after each attempt, writes in the backlog what the base still lacks, zone by
zone (data/cache/loops/base/backlog.md). It never validates anything; the arbiter does not read it."""

from __future__ import annotations

from pathlib import Path

from pipeline import storage
from tools.loop import backlog

SIDE = "alliance"


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    from pipeline.zones.__main__ import selected
    lacking = []
    for path in sorted(storage.ZONES_DIR.glob("**/quests.json")):
        quests = [q for q in ((storage.read_json(path) or {}).get("quests") or {}).values()
                  if selected(q, SIDE, None)]
        no_desc = sum(1 for q in quests if not q.get("description"))
        no_end = sum(1 for q in quests if not q.get("completion"))
        if no_desc or no_end:
            key = str(path.parent.relative_to(storage.ZONES_DIR))
            lacking.append((no_desc + no_end, f"{key}: {no_desc} without French description, {no_end} without "
                                              f"French completion"))
    entry = {"checked": storage.now(), "last exit code": exit_code, "level": answer.get("level"),
             "zones lacking French texts (in-game capture), most first": [t for _, t in sorted(lacking, reverse=True)],
             "errors in the last output": backlog.error_lines(output_tail)}
    backlog.record(run_dir, "all", entry)
