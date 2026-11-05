"""Start of a run of the dialogues loop: the dialogue readings not found in the last run get a fresh budget of
takes (never abandoned), as tools/readings/reopen.py does for the quest readings.

    .venv/bin/python -m tools.dialogues.reopen
"""

from __future__ import annotations

import json

from tools.dialogues import judge
from tools.readings.reopen import reopen


def main() -> None:
    total = 0
    for path in sorted(judge.ZONES.glob("**/dialogue_readings.json")):
        state = json.loads(path.read_text(encoding="utf-8"))
        opened = reopen(state)
        if opened:
            judge._write(path, state)
            total += len(opened)
    print(f"dialogues: new run, {total} reading(s) not in place get {judge.MAX_TRIES} more takes")


if __name__ == "__main__":
    main()
