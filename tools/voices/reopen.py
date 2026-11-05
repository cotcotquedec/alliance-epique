"""Start of a run of the voice loop: the NPCs without a voice get a fresh budget of takes (2026-10-07).

An NPC is never abandoned: after the judge's MAX_TRIES failed takes in a run it is "not_found" until the next run.
This step, run by tools/voices/run.sh before the loop, reopens every NPC without a validated voice: status
"pending" and no take yet in this run (campaign_tries 0). Its takes so far stay counted (tries, seeds never
reused), so the ratchet does not move.

    .venv/bin/python -m tools.voices.reopen
"""

from __future__ import annotations

import json

from tools.voices import judge, oracle


def reopen(voices: dict) -> list[str]:
    """Reopens the NPCs without a validated voice in `voices` (the whole voices.json); returns their ids."""
    out = []
    for n, record in voices["npcs"].items():
        entry = record.get("qwen")
        if not entry or oracle.settled(entry) == "ok":
            continue
        if entry.get("status") != "pending" or entry.get("campaign_tries"):
            entry["status"], entry["campaign_tries"] = "pending", 0
            out.append(n)
    return out


def main() -> None:
    voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))
    opened = reopen(voices)
    if opened:
        judge._write(judge.VOICES_FILE, voices)
    names = ", ".join(f"{n} {voices['npcs'][n]['name']}" for n in opened)
    print(f"voices: new run, {len(opened)} NPC(s) without a voice get {judge.MAX_TRIES} more takes"
          + (f": {names}" if opened else ""))


if __name__ == "__main__":
    main()
