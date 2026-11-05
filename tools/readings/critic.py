"""Critic of the readings pass: after each attempt, writes what the zone still misses in the backlog
(data/cache/loops/readings/backlog.md). It never validates anything; the arbiter does not read it.

Per zone: the readings still to do and why their last take failed, the readings not found in this run (their best
take is on the zone's page), the readings waiting for their NPC's model voice (voice loop), and, over every take
judged so far, the failure rate of each NPC and why: an NPC whose readings often fail may need its model voice
redone (a human decision).
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

from pipeline import storage
from tools.loop import backlog
from tools.readings import judge, oracle, page


def _tries(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def npc_failures(tries: list[dict], limit: int = 15) -> list[str]:
    """'<npc>: <failed>/<takes> failed (reasons)', the worst rates first (NPCs with a failure only)."""
    takes, failed, why = collections.Counter(), collections.Counter(), collections.defaultdict(collections.Counter)
    for t in tries:
        takes[t["npc"]] += 1
        if t["failed"]:
            failed[t["npc"]] += 1
            why[t["npc"]].update(judge.REASONS[f] for f in t["failed"])
    rows = sorted((n for n in takes if failed[n]), key=lambda n: (-failed[n] / takes[n], n))
    return [f"{n}: {failed[n]}/{takes[n]} failed ({', '.join(f'{k} {v}' for k, v in why[n].items())})"
            for n in rows[:limit]]


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    voices = json.loads(judge.voice_judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
    z = oracle.zone_readings(zone, voices)
    state = oracle._read(judge.state_file(zone), {}).get("readings", {})
    tries = _tries(judge.TRIES_LOG)
    last = {}
    for t in tries:
        if t.get("zone") == zone:
            last[t["reading"]] = t

    def why(unit_id):
        failed = (last.get(unit_id) or {}).get("failed") or []
        return f"{unit_id} ({(state.get(unit_id) or {}).get('tries', 0)} tries" + (
            f", last: {', '.join(judge.REASONS[f] for f in failed)})" if failed else ")")

    entry = {"checked": storage.now(), "last exit code": exit_code, "readings in place": z["ok"],
             "readings still to do": [why(u["id"]) for u in z["todo"]],
             "not found in this run (next run: 5 more takes)":
                 [why(k) for k, e in state.items() if e.get("status") == "not_found"],
             "readings waiting for their NPC's model voice": z["waiting_voice"],
             "listening page": str(page.page_path(zone).relative_to(judge.ROOT)),
             "failures by NPC, all takes so far": npc_failures(tries),
             "errors in the last output": backlog.error_lines(output_tail)}
    backlog.record(run_dir, zone, entry)
