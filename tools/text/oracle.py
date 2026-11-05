"""Oracle of the text pass: is every zone's text done? READ-ONLY for the loop.

It reads the data files only, through `tools/zone.sh progress --side alliance --json`: a zone's text is
done when every giver of its Alliance quests has a persona and every quest that can be voiced has a script.
Level (the ratchet's counters): zones with their text, scripts (start and end of quest), personas, quests of
the fetched zones. `todo`: the zones still to do, in level order (the loop can be limited to some of them).

    python -m tools.loop oracle text     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations

import json
import subprocess

from pipeline.storage import REPO_ROOT

CMD = ["tools/zone.sh", "progress", "--side", "alliance", "--json"]
LEVEL = ("zones_text", "scripts_done", "personas", "quests")


def ask(run=subprocess.run) -> dict:
    proc = run(CMD, capture_output=True, text=True, cwd=REPO_ROOT)
    if proc.returncode != 0:
        raise RuntimeError(f"{' '.join(CMD)} exited with {proc.returncode}: {(proc.stderr or proc.stdout)[-500:]}")
    progress = json.loads(proc.stdout.strip().splitlines()[-1])
    return {"done": progress["next_text"] is None, "next": progress["next_text"], "todo": progress["todo_text"],
            "level": {k: int(progress[k]) for k in LEVEL}}

