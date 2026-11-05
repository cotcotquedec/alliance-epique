"""Start of a run of the readings loop: the readings not found in the last run get a fresh budget of takes.

A reading is never abandoned: after the judge's MAX_TRIES failed takes in a run it is "not_found" until the next
run. This step, run by tools/readings/run.sh before the loop, reopens every reading not yet in place: status
"pending", no take yet in this run (campaign_tries 0). Its takes so far stay counted (tries, seeds never reused),
so the ratchet does not move.

    .venv/bin/python -m tools.readings.reopen
"""

from __future__ import annotations

import json

from tools.readings import judge


def reopen(state: dict) -> list[str]:
    """Reopens the readings of a zone's readings.json that are not in place; returns their ids."""
    out = []
    for unit, entry in (state.get("readings") or {}).items():
        if entry.get("status") == "ok":
            continue
        if entry.get("status") != "pending" or entry.get("campaign_tries"):
            entry["status"], entry["campaign_tries"] = "pending", 0
            out.append(unit)
    return out


def main() -> None:
    total = 0
    for path in sorted(judge.ZONES.glob("**/readings.json")):
        state = json.loads(path.read_text(encoding="utf-8"))
        opened = reopen(state)
        if opened:
            judge._write(path, state)
            total += len(opened)
    print(f"readings: new run, {total} reading(s) not in place get {judge.MAX_TRIES} more takes")


if __name__ == "__main__":
    main()
