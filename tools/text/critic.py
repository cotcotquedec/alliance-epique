"""Critic of the text pass: after each attempt, writes what the zone still misses in the backlog
(data/cache/loops/text/backlog.md). It never validates anything; the arbiter does not read it."""

from __future__ import annotations

from pathlib import Path

from pipeline import storage
from pipeline import scripts
from pipeline.personas import generate as personas
from pipeline.zones import catalog as zones
from tools.loop import backlog

SIDE = "alliance"


def missing(zone: str, voices: dict) -> dict:
    from pipeline.zones.__main__ import selected  # the same quest filter as the pass
    folder = zones.zone_dir(zone)
    quests = (storage.read_json(folder / "quests.json") or {}).get("quests")
    if quests is None:
        return {"registry": "not fetched yet (fetch stopped before writing quests.json)"}
    picked = {k: q for k, q in quests.items() if selected(q, SIDE, None)}
    script_file = storage.read_json(folder / "scripts.json")
    out = {}
    for kind, label in (("detail", "start"), ("complete", "end")):
        jobs, skipped = scripts.plan(picked, voices, scripts.section(script_file, kind), kind=kind)
        speakers = {scripts.speaker(q, kind) for q in picked.values() if scripts.text_template(q, kind)["text"]}
        out[f"{label}: speaking NPCs without persona"] = sorted(n for n in speakers - {None} if str(n) not in voices)
        out[f"{label}: quests without script yet"] = sorted([j["quest"]["id"] for j in jobs] + skipped["no_persona"])
        if kind == "detail":  # a quest without completion text simply has no turn-in line
            out[f"{label}: quests without French text (in-game capture)"] = skipped["no_text"]
        out[f"{label}: quests without NPC speaker (narrator voice, D9)"] = skipped[scripts.NO_SPEAKER[kind]]
    return out


def review(zone: str, exit_code: int, output_tail: str, answer: dict, run_dir: Path) -> None:
    entry = {"checked": storage.now(), "last exit code": exit_code,
             **missing(zone, personas.load_voices()["npcs"]),
             "errors in the last output": backlog.error_lines(output_tail)}
    backlog.record(run_dir, zone, entry)
