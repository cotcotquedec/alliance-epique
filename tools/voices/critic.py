"""Critic of the voice pass: after each attempt, writes what the zone still misses in the backlog
(data/cache/loops/voices/backlog.md). It never validates anything; the arbiter does not read it.

Per zone: the NPCs still without a voice (tries, why their last take failed), the NPCs not found in this run
(5 failed takes; the next run reopens them; their best take is on the zone's page), and, over every take judged so far, the failure rate of each race and why: a race
that fails often means its accent (data/accents.json) or its frame needs a human decision.
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

from pipeline import storage
from tools.loop import backlog
from tools.qwen_voices.frame import race_of
from tools.voices import judge, oracle, page


def _tries(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def race_failures(tries: list[dict], voices: dict, accents: dict) -> list[str]:
    """'<race>: <failed>/<takes> failed (anglais n, mots mal lus n, durée n)', worst rate first."""
    takes, failed, why = collections.Counter(), collections.Counter(), collections.defaultdict(collections.Counter)
    for t in tries:
        race = race_of(voices.get(str(t["npc"])) or {}, accents) or accents["default"]
        takes[race] += 1
        if t["failed"]:
            failed[race] += 1
            why[race].update(judge.REASONS[f] for f in t["failed"])
    rows = sorted(takes, key=lambda r: (-failed[r] / takes[r], r))
    return [f"{r}: {failed[r]}/{takes[r]} failed" + (f" ({', '.join(f'{k} {v}' for k, v in why[r].items())})"
                                                     if why[r] else "") for r in rows]


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
    accents = json.loads(page.ACCENTS.read_text(encoding="utf-8"))
    tries = _tries(judge.TRIES_LOG)
    last = {}
    for t in tries:
        last[str(t["npc"])] = t
    ids = [n for n in oracle.zone_npcs(zone) if oracle.speaks(voices.get(n))]
    states = {n: oracle.settled(voices[n].get("qwen")) for n in ids}

    def why(n):
        failed = (last.get(n) or {}).get("failed") or []
        return f"{n} {voices[n]['name']} ({(voices[n].get('qwen') or {}).get('tries', 0)} tries" + (
            f", last: {', '.join(judge.REASONS[f] for f in failed)})" if failed else ")")

    entry = {"checked": storage.now(), "last exit code": exit_code,
             "voices validated": sum(s == "ok" for s in states.values()),
             "NPCs without a voice yet": [why(n) for n in ids if states[n] is None],
             "not found in this run (next run: 5 more takes)": [why(n) for n in ids if states[n] == "not_found"],
             "listening page": str(page.page_path(zone).relative_to(judge.ROOT)),
             "failures by race, all takes so far": race_failures(tries, voices, accents),
             "errors in the last output": backlog.error_lines(output_tail)}
    backlog.record(run_dir, zone, entry)
