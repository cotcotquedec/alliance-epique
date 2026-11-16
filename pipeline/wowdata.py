"""French quest texts of salty-max/wow-data into the zone registries (2026-11-16, the player's decision).

wow-data (https://github.com/salty-max/wow-data) publishes a SQLite build of Forever's data per release
(`forever.db.gz`). Its French quest texts (`quest_text`, locale frFR) all come from Wowhead pages its author saved
from a browser tab ("wowhead (frozen)"): the Forever text, with the game's markers ($B, $N, $g…:…;), more quests than
our own Wowhead cache (stopped 2026-10-12) and the completion texts (`reward`) the client cache lacks. The data is
Blizzard's text, not under the repository's MIT licence: personal use, like the rest of the registries (§3).

Like the captures and the client cache (pipeline/capture_quests.py, pipeline/client_cache.py): only a text the
registry lacks is filled (channel and origin `wowdata`, kept by the base import), never an existing one (D13, a
difference is listed); a text left in English or in brackets is not taken (D5); Horde quests are left out.

    gh release download <tag> -R salty-max/wow-data -p forever.db.gz && gunzip forever.db.gz
    python -m pipeline.captures wowdata forever.db [--zones DIR] [--dry-run]
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

from pipeline.foreverdb.importer import convert_text

FIELDS = {"details": "description", "objectives": "objectives", "reward": "completion"}  # theirs -> ours


def read(db: Path) -> tuple[str, dict[int, dict[str, str | None]]]:
    """-> (release tag, {quest id: {our field: text in our markup}}), French only, bracketed English dropped."""
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        meta = dict(con.execute("SELECT key, value FROM meta"))
        out: dict[int, dict[str, str | None]] = {}
        for qid, field, text in con.execute(
                "SELECT quest_id, field, text FROM quest_text WHERE locale = 'frFR' AND field IN "
                f"({', '.join('?' * len(FIELDS))})", tuple(FIELDS)):
            if "[" in text:  # a name the French client lacks, left in English by the source
                continue
            out.setdefault(qid, {})[FIELDS[field]] = convert_text(text)
    finally:
        con.close()
    return meta.get("tag") or meta.get("built_at") or "?", out
