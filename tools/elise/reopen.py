"""Start of a run of the Elise loop: her lines not found in the last run get a fresh budget of takes (never
abandoned), as tools/readings/reopen.py does for the NPCs' readings.

    .venv/bin/python -m tools.elise.reopen
"""

from __future__ import annotations

from tools.elise import judge


def main() -> None:
    state = judge._read(judge.STATE, None)
    opened = 0
    for entry in ((state or {}).get("lines") or {}).values():
        if entry.get("status") != "ok" and (entry.get("status") != "pending" or entry.get("campaign_tries")):
            entry["status"], entry["campaign_tries"] = "pending", 0
            opened += 1
    if opened:
        judge._write(judge.STATE, state)
    print(f"elise: new run, {opened} line(s) not in place get {judge.MAX_TRIES} more takes")


if __name__ == "__main__":
    main()
