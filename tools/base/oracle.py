"""Oracle of the base pass: are all the zone registries imported from the current Forever Database?
READ-ONLY for the loop.

It reads the registries and the built database (pipeline.foreverdb.importer.status): a zone is to do while
its registry was not written from the current database version. Level (the ratchet's counters): zones with
quests, quests, French descriptions, French completion texts; an import never removes any (texts already in
the registries are kept, see the importer). `next` is "all": the actor imports every zone at once.

    python -m tools.loop oracle base     # prints the answer; exit 0: goal reached, 1: not yet
"""

from __future__ import annotations


def ask(status=None) -> dict:
    from pipeline.foreverdb import importer
    state = (status or importer.status)()
    todo = state["todo"]
    return {"done": state["stamp"] is not None and not todo, "next": "all" if todo or state["stamp"] is None else None,
            "todo": ["all"] if todo or state["stamp"] is None else [], "level": state["level"]}
