"""Start of a run of the books loop: the page readings not found in the last run get a fresh budget of takes (never
abandoned), as tools/elise/reopen.py does for her lines.

    .venv/bin/python -m tools.books.reopen
"""

from __future__ import annotations

from tools.books import judge


def main() -> None:
    state = judge._read(judge.STATE, None)
    opened = 0
    for entry in ((state or {}).get("lines") or {}).values():
        if entry.get("status") != "ok" and (entry.get("status") != "pending" or entry.get("campaign_tries")):
            entry["status"], entry["campaign_tries"] = "pending", 0
            opened += 1
    if opened:
        judge._write(judge.STATE, state)
    print(f"books: new run, {opened} page reading(s) not in place get {judge.MAX_TRIES} more takes")


if __name__ == "__main__":
    main()
