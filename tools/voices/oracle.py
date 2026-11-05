"""Oracle of the voice loop: does every NPC who speaks have a validated voice? READ-ONLY for the loop (sealed).

It only reads: the zones in level order (`tools/zone.sh order --side alliance`), each zone's NPCs
(npcs.json) and data/voices.json. An NPC is to do when it has a persona (with its sample line) and is not
settled. Settled: a voice whose recorded scores pass the judge's thresholds (tools/voices/judge.py `verdict`,
checked again here, without Whisper) and whose file exists ("ok"), or "not_found" after MAX_TRIES failed takes in
this run of the loop (never abandoned: the next run reopens it, tools/voices/reopen.py). NPCs without a persona are
the text loop's job.

Level (the ratchet's counters, they never go down): voices_ok and tries (every take ever judged, archived ones
included), so that reopening the NPCs not found never lowers it, and a pass where every take failed still counts
as progress: within a run, the NPCs still to do, and the tries they have left, only go down. Also reported:
`remaining` (NPCs still to do, all zones), `not_found` (NPCs not found in this run), `todo` (the zones with NPCs
still to do, in level order).

    python -m tools.loop oracle voices     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from tools.voices import judge

CMD = ["tools/zone.sh", "order", "--side", "alliance"]


def zones_dir() -> Path:
    return judge.ROOT / "data" / "zones"


def zones_in_order(run=subprocess.run) -> list[str]:
    proc = run(CMD, capture_output=True, text=True, cwd=judge.ROOT)
    if proc.returncode != 0:
        raise RuntimeError(f"{' '.join(CMD)} exited with {proc.returncode}: {(proc.stderr or proc.stdout)[-500:]}")
    return [line.split("\t")[0] for line in proc.stdout.splitlines() if line.strip()]


def zone_npcs(key: str, zones: Path | None = None) -> list[str]:
    path = (zones or zones_dir()) / key / "npcs.json"
    if not path.exists():
        return []
    return sorted(json.loads(path.read_text(encoding="utf-8")).get("npcs", {}), key=int)


def speaks(record: dict | None) -> bool:
    return bool(((record or {}).get("persona") or {}).get("sample_line"))


def settled(entry: dict | None, root: Path | None = None) -> str | None:
    """"ok", "not_found" (in this run), or None (still to do) for a voices.json qwen entry."""
    entry, root = entry or {}, root or judge.ROOT
    if entry.get("status") == "ok" and entry.get("scores") and not judge.verdict(entry["scores"]) \
            and (root / entry.get("ref", "")).is_file():
        return "ok"
    if entry.get("status") == "not_found" and entry.get("campaign_tries", 0) >= judge.MAX_TRIES:
        return "not_found"
    return None


def only_npcs() -> set[str] | None:
    """The NPCs the run is limited to (`--npc`, environment FS_NPCS), or None: all."""
    raw = os.environ.get("FS_NPCS", "").replace(",", " ").split()
    return set(raw) or None


def pending(key: str, voices: dict, zones: Path | None = None, root: Path | None = None) -> list[str]:
    """The NPCs of a zone still to do (only those of FS_NPCS, if set)."""
    wanted = only_npcs()
    return [n for n in zone_npcs(key, zones) if speaks(voices.get(n)) and not settled(voices[n].get("qwen"), root)
            and (wanted is None or n in wanted)]


def ask(run=subprocess.run, voices_file: Path | None = None, zones: Path | None = None,
        root: Path | None = None) -> dict:
    voices = json.loads((voices_file or judge.VOICES_FILE).read_text(encoding="utf-8"))["npcs"]
    todo, remaining = [], set()
    for key in zones_in_order(run):
        left = pending(key, voices, zones, root)
        if left:
            todo.append(key)
            remaining.update(left)
    states = [settled(r.get("qwen"), root) for r in voices.values()]
    tries = sum((r.get("qwen") or {}).get("tries", 0) + sum(old.get("tries", 0) for old in r.get("qwen_history", []))
                for r in voices.values())
    return {"done": not todo, "next": todo[0] if todo else None, "todo": todo, "remaining": len(remaining),
            "not_found": states.count("not_found"), "level": {"voices_ok": states.count("ok"), "tries": tries}}
